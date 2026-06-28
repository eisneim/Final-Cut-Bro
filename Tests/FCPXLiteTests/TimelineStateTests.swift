import XCTest
@testable import FCPXLite

final class TimelineStateTests: XCTestCase {

    private func emptyStore() -> DocumentStore {
        DocumentStore(document: Document(
            formatWidth: 1920, formatHeight: 1080, frameRate: 25,
            assetLibrary: [], sequence: Sequence(spine: [])))
    }

    // MARK: - EditTool enum

    func testEditToolLabelSelect() {
        XCTAssertEqual(EditTool.select.label, "选择")
    }

    func testEditToolShortcutBlade() {
        XCTAssertEqual(EditTool.blade.shortcut, "B")
    }

    func testEditToolAllCasesCount() {
        XCTAssertEqual(EditTool.allCases.count, 7)
    }

    // MARK: - setTool dispatch

    func testDispatchSetTool() {
        let store = emptyStore()
        store.dispatch(.setTool(.blade))
        XCTAssertEqual(store.ui.currentTool, .blade)
        store.dispatch(.setTool(.select))
        XCTAssertEqual(store.ui.currentTool, .select)
    }

    // MARK: - setZoom clamping

    func testDispatchSetZoomClampsMax() {
        let store = emptyStore()
        store.dispatch(.setZoom(1000))
        XCTAssertEqual(store.ui.pxPerSecond, 400)
    }

    func testDispatchSetZoomClampsMin() {
        let store = emptyStore()
        store.dispatch(.setZoom(0.1))
        XCTAssertEqual(store.ui.pxPerSecond, 1)   // 下限1px/秒(1小时电影整屏)
    }

    func testDispatchSetZoomAllowsOnePxPerSecond() {
        let store = emptyStore()
        store.dispatch(.setZoom(1))
        XCTAssertEqual(store.ui.pxPerSecond, 1)
    }

    func testDispatchSetZoomInRange() {
        let store = emptyStore()
        store.dispatch(.setZoom(60))
        XCTAssertEqual(store.ui.pxPerSecond, 60)
    }

    // MARK: - setTimelineFraction clamping

    func testDispatchSetTimelineFractionClampsMin() {
        let store = emptyStore()
        store.dispatch(.setTimelineFraction(0.01))
        XCTAssertEqual(store.ui.timelineFraction, 0.15)
    }

    func testDispatchSetTimelineFractionClampsMax() {
        let store = emptyStore()
        store.dispatch(.setTimelineFraction(0.99))
        XCTAssertEqual(store.ui.timelineFraction, 0.85)
    }

    func testDispatchSetTimelineFractionInRange() {
        let store = emptyStore()
        store.dispatch(.setTimelineFraction(0.4))
        XCTAssertEqual(store.ui.timelineFraction, 0.4)
    }

    // MARK: - setPlayhead

    func testDispatchSetPlayhead() {
        let store = emptyStore()
        store.dispatch(.setPlayhead(.seconds(3)))
        XCTAssertEqual(store.ui.playhead, .seconds(3))
    }

    // MARK: - UIState Codable round-trip (with new fields)

    func testUIStateCodableRoundTripWithNewFields() throws {
        var state = UIState()
        state.currentTool = .blade
        state.pxPerSecond = 120
        state.playhead = .seconds(5.5)
        state.timelineFraction = 0.4

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(UIState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    // MARK: - EditorAction Codable

    func testSetToolActionCodable() throws {
        let action = EditorAction.setTool(.trim)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(EditorAction.self, from: data)
        XCTAssertEqual(decoded, action)
    }

    func testSetZoomActionCodable() throws {
        let action = EditorAction.setZoom(90)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(EditorAction.self, from: data)
        XCTAssertEqual(decoded, action)
    }
}
