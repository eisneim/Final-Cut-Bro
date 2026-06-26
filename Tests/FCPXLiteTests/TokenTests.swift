import XCTest
import SwiftUI
@testable import FCPXLite

final class TokenTests: XCTestCase {
    func testHexParsesToComponents() {
        // #212121 → (33,33,33)/255
        let c = Color(hex: "#212121")
        let ns = NSColor(c).usingColorSpace(.sRGB)!
        XCTAssertEqual(Double(ns.redComponent), 33.0/255.0, accuracy: 0.01)
        XCTAssertEqual(Double(ns.greenComponent), 33.0/255.0, accuracy: 0.01)
        XCTAssertEqual(Double(ns.blueComponent), 33.0/255.0, accuracy: 0.01)
    }

    func testTokensExist() {
        // 仅验证可访问(编译期保证类型),运行期确认非崩溃。
        _ = Tokens.Palette.chrome
        _ = Tokens.Palette.clipBlue
        _ = Tokens.Palette.selectYellow
        _ = Tokens.Metric.librariesWidth
    }
}
