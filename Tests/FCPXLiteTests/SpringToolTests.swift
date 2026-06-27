import XCTest
@testable import FCPXLite

final class SpringToolTests: XCTestCase {
    func testTapKeepsTool() {
        var s = SpringTool()
        // 按下 blade(当前 select)
        let switched = s.keyDown(tool: .blade, current: .select, time: 100.0, isRepeat: false)
        XCTAssertEqual(switched, .blade)
        // 短按松开(0.1s < 0.25)→ 保持(nil)
        let revert = s.keyUp(time: 100.1)
        XCTAssertNil(revert)
    }

    func testHoldRevertsTool() {
        var s = SpringTool()
        _ = s.keyDown(tool: .position, current: .select, time: 100.0, isRepeat: false)
        // 长按松开(0.5s > 0.25)→ 还原到 select
        let revert = s.keyUp(time: 100.5)
        XCTAssertEqual(revert, .select)
    }

    func testRepeatIgnored() {
        var s = SpringTool()
        _ = s.keyDown(tool: .zoom, current: .select, time: 100.0, isRepeat: false)
        // 自动重复不再切换
        XCTAssertNil(s.keyDown(tool: .zoom, current: .zoom, time: 100.05, isRepeat: true))
    }

    func testKeyUpWithoutHeldNoop() {
        var s = SpringTool()
        XCTAssertNil(s.keyUp(time: 100.0))
    }

    func testHeldShortcut() {
        var s = SpringTool()
        _ = s.keyDown(tool: .hand, current: .select, time: 1, isRepeat: false)
        XCTAssertEqual(s.heldShortcut, "h")
    }
}
