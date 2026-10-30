import XCTest
import CoreGraphics
@testable import MacKitCore

final class DockInteractionTests: XCTestCase {
    func testNavigationBackForwardAndBranching() {
        var history = NavigationHistory(current: "cleaning")
        XCTAssertFalse(history.canGoBack)
        history.visit("finder")
        history.visit("dock")
        XCTAssertEqual(history.back(), "finder")
        history.visit("finder") // UI selection callbacks must preserve forward history.
        XCTAssertTrue(history.canGoForward)
        XCTAssertEqual(history.forward(), "dock")
        XCTAssertEqual(history.back(), "finder")
        history.visit("settings")
        XCTAssertFalse(history.canGoForward)
        XCTAssertEqual(history.back(), "finder")
        XCTAssertEqual(history.back(), "cleaning")
        XCTAssertNil(history.back())
    }

    func testRepeatedNavigationDoesNotAddDuplicatePages() {
        var history = NavigationHistory(current: 1)
        history.visit(1)
        XCTAssertFalse(history.canGoBack)
        XCTAssertNil(history.forward())
    }

    func testQuitProtectionExcludesShellAndOwnApp() {
        for bundle in ["com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.SystemUIServer", "com.apple.controlcenter", "com.apple.systempreferences", "com.mackit.app"] {
            XCTAssertFalse(AppQuitPolicy.allows(bundleID: bundle, ownBundleID: "com.mackit.app"))
        }
        XCTAssertFalse(AppQuitPolicy.allows(bundleID: nil, ownBundleID: "com.mackit.app"))
        XCTAssertTrue(AppQuitPolicy.allows(bundleID: "com.apple.Safari", ownBundleID: "com.mackit.app"))
        XCTAssertTrue(AppQuitPolicy.allows(bundleID: "com.microsoft.VSCode", ownBundleID: "com.mackit.app"))
    }

    func testSwitcherGridAvoidsOneWideRowOnBuiltInDisplay() {
        let columns = SwitcherLayout.columns(count: 12, available: CGSize(width: 1512, height: 900), targetAspect: 1.6)
        XCTAssertEqual(columns, 4)
        XCTAssertLessThan(columns, 6)
        let portrait = SwitcherLayout.columns(count: 8, available: CGSize(width: 1080, height: 1920), targetAspect: 1.6)
        XCTAssertEqual(portrait, 4)
        XCTAssertEqual(SwitcherLayout.columns(count: 1, available: CGSize(width: 300, height: 500), targetAspect: 1.6), 1)
    }

    func testWindowlessAppsFollowBothNormalAndMinimizedWindows() {
        let ordinary = WindowPresence.orderGroup(windowless: false, minimized: false)
        let minimized = WindowPresence.orderGroup(windowless: false, minimized: true)
        XCTAssertLessThan(ordinary, minimized)
        for hidden in [false, true] {
            XCTAssertLessThan(minimized, WindowPresence.orderGroup(windowless: true, minimized: hidden))
        }
    }

    func testClosedBackingSurfacesCannotReturnAsWindows() {
        XCTAssertFalse(WindowPresence.permitsSurface(axAnswered: true, onScreen: true, hasTitle: true))
        XCTAssertFalse(WindowPresence.permitsSurface(axAnswered: true, onScreen: false, hasTitle: true))
        XCTAssertFalse(WindowPresence.permitsSurface(axAnswered: false, onScreen: false, hasTitle: true))
        XCTAssertFalse(WindowPresence.permitsSurface(axAnswered: false, onScreen: true, hasTitle: false))
        XCTAssertTrue(WindowPresence.permitsSurface(axAnswered: false, onScreen: true, hasTitle: true))
    }

    func testNativeClicksArePreservedForBackgroundAndUnownedMinimization() {
        XCTAssertEqual(DockClickPolicy.intent(active: false, lastMinimized: nil, elapsed: .infinity), .native)
        XCTAssertEqual(DockClickPolicy.intent(active: false, lastMinimized: false, elapsed: 3), .native)
        XCTAssertEqual(DockClickPolicy.intent(active: true, lastMinimized: nil, elapsed: .infinity), .minimize)
    }

    func testAnimationIntentAndDoubleClickDebounce() {
        XCTAssertEqual(DockClickPolicy.intent(active: true, lastMinimized: true, elapsed: 0.1), .ignore)
        XCTAssertEqual(DockClickPolicy.intent(active: true, lastMinimized: true, elapsed: 0.4), .restore)
        XCTAssertEqual(DockClickPolicy.intent(active: false, lastMinimized: false, elapsed: 0.4), .minimize)
        XCTAssertEqual(DockClickPolicy.intent(active: false, lastMinimized: true, elapsed: 10), .restore)
    }

    func testDragThreshold() {
        XCTAssertFalse(DockGeometry.isDrag(from: .zero, to: CGPoint(x: 3, y: 4)))
        XCTAssertFalse(DockGeometry.isDrag(from: .zero, to: CGPoint(x: 6, y: 0)))
        XCTAssertTrue(DockGeometry.isDrag(from: .zero, to: CGPoint(x: 7, y: 0)))
    }

    func testPanelClampsOnNegativeCoordinateDisplay() {
        let screen = CGRect(x: -1600, y: -900, width: 1600, height: 900)
        for edge in [DockEdge.bottom, .left, .right] {
            let result = DockGeometry.panel(anchor: CGRect(x: -1590, y: -890, width: 60, height: 60),
                                            size: CGSize(width: 900, height: 1000), screen: screen, edge: edge)
            XCTAssertTrue(screen.contains(result))
            XCTAssertGreaterThan(result.width, 0)
            XCTAssertGreaterThan(result.height, 0)
        }
    }

    func testOpeningCorridorDoesNotCoverUnrelatedDesktop() {
        let icon = CGRect(x: 400, y: 0, width: 64, height: 64)
        let panel = CGRect(x: 200, y: 90, width: 600, height: 200)
        XCTAssertTrue(DockGeometry.openingPath(CGPoint(x: 430, y: 75), icon: icon, panel: panel, edge: .bottom))
        XCTAssertFalse(DockGeometry.openingPath(CGPoint(x: 750, y: 75), icon: icon, panel: panel, edge: .bottom))
        let sideIcon = CGRect(x: 0, y: 300, width: 64, height: 64)
        let sidePanel = CGRect(x: 90, y: 100, width: 228, height: 600)
        XCTAssertTrue(DockGeometry.openingPath(CGPoint(x: 75, y: 330), icon: sideIcon, panel: sidePanel, edge: .left))
        XCTAssertFalse(DockGeometry.openingPath(CGPoint(x: 75, y: 600), icon: sideIcon, panel: sidePanel, edge: .left))
    }

    func testLayoutFollowsDockEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let icon = CGRect(x: 700, y: 400, width: 64, height: 64)
        let size = CGSize(width: 228, height: 208)
        XCTAssertGreaterThan(DockGeometry.panel(anchor: icon, size: size, screen: screen, edge: .bottom).minY, icon.maxY)
        XCTAssertGreaterThan(DockGeometry.panel(anchor: icon, size: size, screen: screen, edge: .left).minX, icon.maxX)
        XCTAssertLessThan(DockGeometry.panel(anchor: icon, size: size, screen: screen, edge: .right).maxX, icon.minX)
    }
}
