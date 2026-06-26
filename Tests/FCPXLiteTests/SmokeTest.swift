import XCTest
@testable import FCPXLite

final class SmokeTest: XCTestCase {
    func testModuleLoads() {
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [], sequence: Sequence(spine: []))
        XCTAssertEqual(doc.formatWidth, 1920)
    }
}
