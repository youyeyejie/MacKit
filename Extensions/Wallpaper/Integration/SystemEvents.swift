// Adapted from Phosphene (MIT), Copyright (c) 2026 kageroumado. See LICENSES/Phosphene-LICENSE.txt and THIRD_PARTY_NOTICES.md.
import AppKit
import CoreGraphics

/// Turns display sleep/wake and loginwindow lock/unlock into playback events.
enum SystemEvents {
    static func start() {
        PlaybackStore.post(.screenLockChanged(isScreenLockedNow()))

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
            extensionLog("[Extension] Displays asleep")
            PlaybackStore.post(.displaysAsleepChanged(true))
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
            extensionLog("[Extension] Displays awake")
            PlaybackStore.post(.displaysAsleepChanged(false))
            ShuffleController.shared.noteWake()
        }

        // loginwindow reports the lock before WallpaperAgent updates any surface, which
        // is what lets the lock screen start playing without waiting on the agent.
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            extensionLog("[Extension] Screen locked")
            PlaybackStore.post(.screenLockChanged(true))
            MacKitRouting.lockChanged(true)
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            extensionLog("[Extension] Screen unlocked")
            PlaybackStore.post(.screenLockChanged(false))
            MacKitRouting.lockChanged(false)
            ShuffleController.shared.noteWake()
        }
    }

    /// The lock state at launch, before any notification arrives.
    private static func isScreenLockedNow() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
