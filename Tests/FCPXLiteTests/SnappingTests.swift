import XCTest
@testable import FCPXLite

final class SnappingTests: XCTestCase {
    func testSnapsToNearestWithinThreshold() {
        let t = Time.seconds(2.03)
        let r = Snapping.snap(t, candidates: [.seconds(2.0), .seconds(5.0)],
                              threshold: .seconds(0.05))
        XCTAssertEqual(r, .seconds(2.0))
    }

    func testNoSnapBeyondThreshold() {
        let t = Time.seconds(2.5)
        let r = Snapping.snap(t, candidates: [.seconds(2.0)], threshold: .seconds(0.05))
        XCTAssertEqual(r, t)
    }

    func testEmptyCandidatesReturnsInput() {
        let t = Time.seconds(1.0)
        XCTAssertEqual(Snapping.snap(t, candidates: [], threshold: .seconds(1)), t)
    }

    func testPicksNearestAmongMany() {
        let t = Time.seconds(4.96)
        let r = Snapping.snap(t, candidates: [.seconds(2), .seconds(5), .seconds(8)],
                              threshold: .seconds(0.1))
        XCTAssertEqual(r, .seconds(5))
    }
}
