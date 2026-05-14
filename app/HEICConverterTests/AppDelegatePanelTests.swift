import XCTest
import AppKit
@testable import HEICConverter

final class AppDelegatePanelTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = NSSize(width: 340, height: 500)

    func testOriginInsideScreen_isUnchanged() {
        let result = AppDelegate.clampedToScreen(origin: NSPoint(x: 600, y: 600), size: size, visibleFrame: screen)
        XCTAssertEqual(result.x, 600, accuracy: 0.001)
        XCTAssertEqual(result.y, 600, accuracy: 0.001)
    }

    func testOriginPastRightEdge_clampsLeftward() {
        let result = AppDelegate.clampedToScreen(origin: NSPoint(x: 1400, y: 600), size: size, visibleFrame: screen)
        // maxX = 1440 - 340 - 8 = 1092
        XCTAssertEqual(result.x, 1092, accuracy: 0.001)
    }

    func testOriginPastLeftEdge_clampsRightward() {
        let result = AppDelegate.clampedToScreen(origin: NSPoint(x: -50, y: 600), size: size, visibleFrame: screen)
        // minX = 0 + 8 = 8
        XCTAssertEqual(result.x, 8, accuracy: 0.001)
    }

    func testYIsNeverClamped() {
        let result = AppDelegate.clampedToScreen(origin: NSPoint(x: 600, y: 99_999), size: size, visibleFrame: screen)
        XCTAssertEqual(result.y, 99_999, accuracy: 0.001,
                       "Y clamping is intentionally not implemented — panel hangs from menu bar at fixed top.")
    }
}
