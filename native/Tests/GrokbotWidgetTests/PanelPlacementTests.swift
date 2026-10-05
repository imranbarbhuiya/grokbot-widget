import XCTest
@testable import GrokbotWidget

final class PanelPlacementTests: XCTestCase {
    let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    func testTopEdgeOpensBelowAndKeepsTopAnchor() {
        let collapsed = NSRect(x: 1100, y: 650, width: 190, height: 230)
        let result = PanelPlacement.expanded(from: collapsed, within: screen)
        XCTAssertTrue(result.below)
        XCTAssertEqual(result.frame.maxY, collapsed.maxY)
        XCTAssertTrue(screen.contains(result.frame))
    }

    func testBottomEdgeOpensAboveAndKeepsBottomAnchor() {
        let collapsed = NSRect(x: 1100, y: 20, width: 190, height: 230)
        let result = PanelPlacement.expanded(from: collapsed, within: screen)
        XCTAssertFalse(result.below)
        XCTAssertEqual(result.frame.minY, collapsed.minY)
        XCTAssertTrue(screen.contains(result.frame))
    }

    func testLeftEdgeAndSmallScreenStayVisible() {
        let bounds = NSRect(x: -800, y: 40, width: 800, height: 580)
        let collapsed = NSRect(x: -795, y: 350, width: 190, height: 230)
        let result = PanelPlacement.expanded(from: collapsed, within: bounds)
        XCTAssertTrue(bounds.contains(result.frame))
        XCTAssertEqual(result.frame.height, bounds.height)
        XCTAssertEqual(result.frame.minX, bounds.minX)
    }
}
