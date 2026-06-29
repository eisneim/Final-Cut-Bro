import XCTest
@testable import FCPXLite

final class GapInteractionTests: XCTestCase {
    private func gapSeq() -> (Sequence, GapID) {
        let c = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(5))
        let g = GapID()
        return (Sequence(spine: [.clip(c), .gap(id: g, duration: .seconds(3))]), g)
    }

    func testSetGapDurationByIDPreservesID() {
        let (seq, g) = gapSeq()
        let out = Mutations.setGapDurationByID(g, duration: .seconds(7), in: seq)
        XCTAssertEqual(out.spine[1].gapID, g, "id 不变(选中态不丢)")
        XCTAssertEqual(out.spine[1].duration, .seconds(7))
    }

    func testRemoveGap() {
        let (seq, g) = gapSeq()
        let out = Mutations.removeGap(g, in: seq)
        XCTAssertEqual(out.spine.count, 1)
        XCTAssertNil(out.spine.first?.gapID)
    }

    func testMoveGapReorders() {
        // [clip(5), gap(3)] 把 gap 移到 0s → gap 应排到最前
        let (seq, g) = gapSeq()
        let out = Mutations.moveGap(g, toTime: .zero, in: seq)
        XCTAssertEqual(out.spine[0].gapID, g, "gap 移到最前")
    }

    func testGapHasStableID() {
        // 同一 gap 经多次 resize id 不变 → UI 选中可持续
        let (seq, g) = gapSeq()
        var s = seq
        s = Mutations.setGapDurationByID(g, duration: .seconds(4), in: s)
        s = Mutations.setGapDurationByID(g, duration: .seconds(6), in: s)
        XCTAssertEqual(s.spine[1].gapID, g)
    }
}

extension GapInteractionTests {
    // P模式向上拖主轨clip:源处留灰条 + clip变连接片段。
    func testPositionMoveToLaneLeavesGap() {
        let c0 = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(4))
        let c1 = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(4))
        let seq = Sequence(spine: [.clip(c0), .clip(c1)])  // 0..4, 4..8
        // 把 c0 拖到 lane 1, 时间2s
        let out = Mutations.positionMoveToLane(clipID: c0.id, toLane: 1, atTime: .seconds(2), in: seq)
        // 源处(spine[0])应变成 gap
        XCTAssertNotNil(out.spine[0].gapID, "源处应留灰条")
        // c0 现在是某主轴 clip 的连接片段
        let isConnected = out.spine.contains { el in
            if case .clip(let h) = el { return h.connected.contains { $0.id == c0.id } }
            return false
        }
        XCTAssertTrue(isConnected, "c0 应变成连接片段")
    }
}
