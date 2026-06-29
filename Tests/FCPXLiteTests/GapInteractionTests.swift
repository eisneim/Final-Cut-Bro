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
