import XCTest
@testable import FCPXLite

/// 导出错误信息可读(CustomStringConvertible)—— 卡死/失败时 UI 显示的是人话,不是枚举语法。
final class ExportErrorMessageTests: XCTestCase {
    func testReadableDescriptions() {
        XCTAssertEqual("\(MovieExportError.emptyTimeline)", "时间线为空,无可导出内容")
        XCTAssertTrue("\(MovieExportError.stalled("停在 80%"))".contains("卡住"))
        XCTAssertTrue("\(MovieExportError.stalled("停在 80%"))".contains("停在 80%"))
        XCTAssertTrue("\(MovieExportError.readerFailed("音频轨"))".contains("读取素材失败"))
        XCTAssertTrue("\(MovieExportError.sessionFailed("x"))".contains("导出会话失败"))
    }
}
