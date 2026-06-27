import XCTest
@testable import FCPXLite

/// 轨道磁吸:拖到副轨道时,connected 片段应压缩到邻近层级(中间空 → 弹回 ±1)。
final class LaneMagnetTests: XCTestCase {
    private func clip(_ secs: Double) -> Clip {
        Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(secs))
    }

    func testDragUpToLane3LandsOnLane1WhenEmpty() {
        // 主轴 [A(2s), B(3s)];把 B relocate 到 lane 3,但 +1/+2 空 → 应落在 lane 1。
        let a = clip(2), b = clip(3)
        let seq0 = Sequence(spine: [.clip(a), .clip(b)])
        let seq1 = Mutations.relocate(clipID: b.id, toLane: 3, atTime: .seconds(0.5), in: seq0)
        let conn = Layout.compute(seq1).filter(\.isConnected)
        XCTAssertEqual(conn.count, 1)
        XCTAssertEqual(conn.first?.lane, 1)   // 弹回 ±1
    }

    func testDragDownToLaneMinus3LandsOnMinus1() {
        let a = clip(2), b = clip(3)
        let seq0 = Sequence(spine: [.clip(a), .clip(b)])
        let seq1 = Mutations.relocate(clipID: b.id, toLane: -3, atTime: .seconds(0.5), in: seq0)
        let conn = Layout.compute(seq1).filter(\.isConnected)
        XCTAssertEqual(conn.first?.lane, -1)
    }

    func testStacksToLane2WhenLane1Occupied() {
        // A(主轴 5s);先在 lane 1 挂一个占 [0,2);再把另一个拖到 lane 1 的重叠时间 → 应落 lane 2。
        let a = clip(5)
        var seq = Sequence(spine: [.clip(a)])
        let first = clip(2)
        seq = Mutations.connectClip(first, toHostIndex: 0, lane: 1, offset: .zero, in: seq)
        // 新片段在库外构造,先插主轴再 relocate(模拟从主轴拖上去)
        let second = clip(2)
        seq.spine.append(.clip(second))
        let out = Mutations.relocate(clipID: second.id, toLane: 1, atTime: .seconds(0.5), in: seq)
        let conn = Layout.compute(out).filter(\.isConnected)
        // 两个连接片段:lane 1 和 lane 2(第二个被磁吸到 2 因为 1 在该时间被占)
        XCTAssertEqual(Set(conn.map(\.lane)), Set([1, 2]))
    }
}
