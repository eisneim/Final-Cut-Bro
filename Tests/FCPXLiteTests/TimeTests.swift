import XCTest
@testable import FCPXLite

final class TimeTests: XCTestCase {
    func testAddSameTimescale() {
        let a = Time(value: 100, timescale: 600)
        let b = Time(value: 200, timescale: 600)
        XCTAssertEqual(a + b, Time(value: 300, timescale: 600))
    }

    func testAddDifferentTimescaleCommonizes() {
        let a = Time(value: 1, timescale: 2)   // 0.5s
        let b = Time(value: 1, timescale: 3)   // 0.333..s
        // 0.5 + 0.3333 = 0.8333.. -> 5/6
        XCTAssertEqual((a + b).seconds, 5.0/6.0, accuracy: 1e-9)
    }

    func testComparable() {
        XCTAssertLessThan(Time(value: 1, timescale: 600), Time(value: 2, timescale: 600))
        XCTAssertLessThan(Time(value: 1, timescale: 3), Time(value: 1, timescale: 2))
    }

    func testScaleByRatio() {
        let a = Time(value: 600, timescale: 600) // 1s
        XCTAssertEqual((a * 0.5).seconds, 0.5, accuracy: 1e-9)
    }

    func testClamp() {
        let lo = Time(value: 0, timescale: 600)
        let hi = Time(value: 600, timescale: 600)
        XCTAssertEqual(Time(value: -10, timescale: 600).clamped(to: lo...hi), lo)
        XCTAssertEqual(Time(value: 900, timescale: 600).clamped(to: lo...hi), hi)
        XCTAssertEqual(Time(value: 300, timescale: 600).clamped(to: lo...hi), Time(value: 300, timescale: 600))
    }

    func testFcpxmlString() {
        XCTAssertEqual(Time(value: 3600, timescale: 600).fcpxmlString, "3600/600s")
        XCTAssertEqual(Time.zero.fcpxmlString, "0s")
    }

    func testHashConsistentWithEquality() {
        let a = Time(value: 1, timescale: 2)
        let b = Time(value: 3, timescale: 6)   // 都是 0.5s
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }
}
