import XCTest
import CoreGraphics
@testable import FCPXLite

/// 素材池 strip 布局纯数学。
final class AssetStripLayoutTests: XCTestCase {
    func testCellWidthScalesWithDurationAndZoom() {
        XCTAssertEqual(AssetStripLayout.cellWidth(durationSecs: 10, pxPerSecond: 8, minTile: 60, availWidth: 800), 80, accuracy: 0.01)
        XCTAssertEqual(AssetStripLayout.cellWidth(durationSecs: 10, pxPerSecond: 20, minTile: 60, availWidth: 800), 200, accuracy: 0.01)
    }

    func testCellWidthClampedToMinTile() {
        // 很短片段 + 小缩放 → 不小于 minTile
        XCTAssertEqual(AssetStripLayout.cellWidth(durationSecs: 1, pxPerSecond: 4, minTile: 60, availWidth: 800), 60, accuracy: 0.01)
    }

    func testCellWidthClampedToAvailWidth() {
        // 超长片段 → 不超过容器宽(单条不跨行)
        XCTAssertEqual(AssetStripLayout.cellWidth(durationSecs: 600, pxPerSecond: 20, minTile: 60, availWidth: 300), 300, accuracy: 0.01)
    }

    func testFlowWrapsWhenRowFull() {
        // 三个 100 宽,容器 250,间距 0 → 行: [0,1],[2]
        let rows = AssetStripLayout.flow(itemWidths: [100, 100, 100], availWidth: 250, spacing: 0)
        XCTAssertEqual(rows, [[0, 1], [2]])
    }

    func testFlowAccountsForSpacing() {
        // 100+10+100=210 <=250 ✓; +10+100=320 >250 → 换行
        let rows = AssetStripLayout.flow(itemWidths: [100, 100, 100], availWidth: 250, spacing: 10)
        XCTAssertEqual(rows, [[0, 1], [2]])
    }

    func testFlowSingleWideItemGetsOwnRow() {
        let rows = AssetStripLayout.flow(itemWidths: [300, 100], availWidth: 250, spacing: 8)
        // 300 自己一行(虽然超宽,cellWidth 已夹到 availWidth,这里直接放),100 下一行
        XCTAssertEqual(rows, [[0], [1]])
    }

    func testFlowAllFitOneRow() {
        let rows = AssetStripLayout.flow(itemWidths: [50, 50, 50], availWidth: 800, spacing: 8)
        XCTAssertEqual(rows, [[0, 1, 2]])
    }

    func testFlowEmpty() {
        XCTAssertEqual(AssetStripLayout.flow(itemWidths: [], availWidth: 800, spacing: 8), [])
    }

    func testRowCountSingleWhenFits() {
        // 10s × 8px = 80 ≤ 300 → 1 行
        XCTAssertEqual(AssetStripLayout.rowCount(durationSecs: 10, pxPerSecond: 8, availWidth: 300), 1)
    }

    func testRowCountWrapsWhenWide() {
        // 100s × 8px = 800,容器 300 → ceil(800/300)=3 行
        XCTAssertEqual(AssetStripLayout.rowCount(durationSecs: 100, pxPerSecond: 8, availWidth: 300), 3)
    }

    func testRowCountExactMultiple() {
        // 600px / 300 = 2 行
        XCTAssertEqual(AssetStripLayout.rowCount(durationSecs: 60, pxPerSecond: 10, availWidth: 300), 2)
    }
}
