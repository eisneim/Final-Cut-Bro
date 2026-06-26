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
        // 两个 connected clip 挂在同一宿主上,absStart 相同(同宿主起点)但 lane 不同
        // Layout.compute 应按 lane 升序排列
        let connLane2 = clip(1, lane: 2, offset: .zero)
        let connLane1 = clip(1, lane: 1, offset: .zero)
        // 故意以 lane 2 先于 lane 1 的顺序挂上,验证输出是按 lane 升序而非插入顺序
        let host = clip(3, connected: [connLane2, connLane1])
        let seq = Sequence(spine: [.clip(host)])
        let placed = Layout.compute(seq)
        let connPlaced = placed.filter(\.isConnected)
        XCTAssertEqual(connPlaced.count, 2)
        // 相同 absStart 时,lane 较小的应排在前面
        XCTAssertEqual(connPlaced[0].lane, 1)
        XCTAssertEqual(connPlaced[1].lane, 2)
        XCTAssertEqual(connPlaced[0].absStart, connPlaced[1].absStart,
                       "两个 connected 的 absStart 应相同(同宿主起点 + offset 0)")
    }
}
