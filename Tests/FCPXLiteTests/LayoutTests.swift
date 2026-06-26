import XCTest
@testable import FCPXLite

final class LayoutTests: XCTestCase {
    private func clip(_ secs: Double, lane: Int = 0, offset: Time = .zero,
                      connected: [Clip] = []) -> Clip {
        Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(secs),
             connected: connected, lane: lane, offset: offset)
    }

    func testPrefixSumPositions() {
        let seq = Sequence(spine: [.clip(clip(2)), .clip(clip(3)), .clip(clip(1))])
        let placed = Layout.compute(seq)
        XCTAssertEqual(placed.map(\.absStart), [.seconds(0), .seconds(2), .seconds(5)])
    }

    func testGapAdvancesTimeButNoPlaced() {
        let seq = Sequence(spine: [.clip(clip(2)), .gap(duration: .seconds(4)), .clip(clip(1))])
        let placed = Layout.compute(seq)
        XCTAssertEqual(placed.count, 2)
        XCTAssertEqual(placed.last?.absStart, .seconds(6)) // 2 + 4
    }

    func testConnectedClipAnchoredToHostStart() {
        // 主轴: A(2s) 起点0, B(3s) 起点2; B 上挂 connected offset=1, lane=1
        let conn = clip(1, lane: 1, offset: .seconds(1))
        let seq = Sequence(spine: [.clip(clip(2)), .clip(clip(3, connected: [conn]))])
        let placed = Layout.compute(seq)
        let c = placed.first { $0.isConnected }
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.absStart, .seconds(3)) // 宿主起点2 + offset1
        XCTAssertEqual(c?.lane, 1)
    }

    func testDeterministicOrdering() {
        let seq = Sequence(spine: [.clip(clip(2)), .clip(clip(3))])
        XCTAssertEqual(Layout.compute(seq), Layout.compute(seq))
    }
}
