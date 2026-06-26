import XCTest
@testable import FCPXLite

final class SmokeTest: XCTestCase {
    func testBuildSmoke() {
        XCTAssertTrue(BuildSmoke.ok)
    }
}
