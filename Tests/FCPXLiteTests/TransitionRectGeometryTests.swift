import XCTest
@testable import FCPXLite

/// 转场时间线标记的纯几何(transitionRect)。
final class TransitionRectGeometryTests: XCTestCase {
    func testCentersOnSeamWithWidthFromDuration() {
        // 接缝 x=300,crossfade=1s,60px/s → 宽60,跨缝两侧各30
        let r = TimelineGeometry.transitionRect(seamX: 300, crossfadeSecs: 1, pxPerSecond: 60,
                                                laneY: 100, laneHeight: 50)
        XCTAssertEqual(r.midX, 300, accuracy: 0.001, "以接缝为中心")
        XCTAssertEqual(r.width, 60, accuracy: 0.001)
        XCTAssertEqual(r.minX, 270, accuracy: 0.001)
        XCTAssertEqual(r.origin.y, 100)
        XCTAssertEqual(r.height, 50)
    }

    func testMinimumWidthForVisibility() {
        // 很短的转场在低缩放下仍保证最小可见宽
        let r = TimelineGeometry.transitionRect(seamX: 100, crossfadeSecs: 0.01, pxPerSecond: 10,
                                                laneY: 0, laneHeight: 40)
        XCTAssertGreaterThanOrEqual(r.width, 6, "最小宽度保证可见")
        XCTAssertEqual(r.midX, 100, accuracy: 0.001)
    }

    func testWidthScalesWithZoom() {
        let low = TimelineGeometry.transitionRect(seamX: 0, crossfadeSecs: 2, pxPerSecond: 30, laneY: 0, laneHeight: 1)
        let high = TimelineGeometry.transitionRect(seamX: 0, crossfadeSecs: 2, pxPerSecond: 120, laneY: 0, laneHeight: 1)
        XCTAssertEqual(low.width, 60, accuracy: 0.001)
        XCTAssertEqual(high.width, 240, accuracy: 0.001)
    }
}
