/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See THIRD_PARTY_NOTICES.md for the original NOTICE and attribution.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import Darwin

/// Small Spaces API wrapper.
public final class CGSSpace {
    private let identifier: CGSSpaceID
    private let createdByInit: Bool

    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private static let copyDisplaySpaces: CopyDisplaySpaces? = {
        guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        else { return nil }
        guard let symbol = dlsym(library, "SLSCopyManagedDisplaySpaces") else {
            dlclose(library)
            return nil
        }
        return unsafeBitCast(symbol, to: CopyDisplaySpaces.self)
    }()

    static func activeFullscreenOwner(on displayID: CGDirectDisplayID) -> pid_t? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
            let identifier = CFUUIDCreateString(nil, uuid) as String?,
            let displays = copyDisplaySpaces?(Int32(truncatingIfNeeded: _CGSDefaultConnection()))?
                .takeRetainedValue() as? [[String: Any]],
            let display = displays.first(where: { info in
                guard let value = info["Display Identifier"] as? String else { return false }
                return value.caseInsensitiveCompare(identifier) == .orderedSame
                    || (value == "Main" && CGDisplayIsMain(displayID) != 0)
            }),
            let space = display["Current Space"] as? [String: Any],
            (space["type"] as? NSNumber)?.intValue == 4,
            let pid = (space["pid"] as? NSNumber)?.int32Value, pid > 0
        else { return nil }
        return pid
    }

    public var windows: Set<NSWindow> = [] {
        didSet {
            let remove = oldValue.subtracting(self.windows)
            let add = self.windows.subtracting(oldValue)

            CGSRemoveWindowsFromSpaces(
                _CGSDefaultConnection(),
                remove.map { $0.windowNumber } as NSArray,
                [self.identifier])
            CGSAddWindowsToSpaces(
                _CGSDefaultConnection(),
                add.map { $0.windowNumber } as NSArray,
                [self.identifier])
        }
    }

    /// Initialized `CGSSpace`s *MUST* be de-initialized upon app exit!
    public init(level: Int = 0) {
        let flag = 0x1  // this value MUST be 1, otherwise, Finder decides to draw desktop icons
        self.identifier = CGSSpaceCreate(_CGSDefaultConnection(), flag, nil)
        CGSSpaceSetAbsoluteLevel(_CGSDefaultConnection(), self.identifier, level)
        CGSShowSpaces(_CGSDefaultConnection(), [self.identifier])
        self.createdByInit = true  // Mark as created by the first init
    }

    public init(id: UInt64) {
        let flag = 0x1  // this value MUST be 1, otherwise, Finder decides to draw desktop icons
        self.identifier = id
        CGSShowSpaces(_CGSDefaultConnection(), [self.identifier])
        self.createdByInit = false  // Mark as created externally
    }

    deinit {
        CGSHideSpaces(_CGSDefaultConnection(), [self.identifier])
        // Only call CGSSpaceDestroy if the space was created by the first init
        if createdByInit {
            CGSSpaceDestroy(_CGSDefaultConnection(), self.identifier)
        }
    }
}

// CGSSpace stuff:
private typealias CGSConnectionID = UInt
private typealias CGSSpaceID = UInt64
@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> CGSConnectionID
@_silgen_name("CGSSpaceCreate")
private func CGSSpaceCreate(_ cid: CGSConnectionID, _ unknown: Int, _ options: NSDictionary?) -> CGSSpaceID
@_silgen_name("CGSSpaceDestroy")
private func CGSSpaceDestroy(_ cid: CGSConnectionID, _ space: CGSSpaceID)
@_silgen_name("CGSSpaceSetAbsoluteLevel")
private func CGSSpaceSetAbsoluteLevel(_ cid: CGSConnectionID, _ space: CGSSpaceID, _ level: Int)
@_silgen_name("CGSAddWindowsToSpaces")
private func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
@_silgen_name("CGSRemoveWindowsFromSpaces")
private func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
@_silgen_name("CGSHideSpaces")
private func CGSHideSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)
@_silgen_name("CGSShowSpaces")
private func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)
