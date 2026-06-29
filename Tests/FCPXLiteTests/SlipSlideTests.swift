import XCTest
@testable import FCPXLite

/// T10:slip(改入出点不改位置时长)/ slide(移片段并调两侧)纯逻辑测试。
final class SlipSlideTests: XCTestCase {
    // 三段各 5s 的主轴,素材都 20s(有充足余量)。
    private func seq3() -> Sequence {
        let mk = { Clip(assetID: AssetID(), sourceIn: .seconds(2), duration: .seconds(5)) }
        return Sequence(spine: [.clip(mk()), .clip(mk()), .clip(mk())])
    }
    private func clip(_ s: Sequence, _ i: Int) -> Clip? {
        guard s.spine.indices.contains(i), case .clip(let c) = s.spine[i] else { return nil }
        return c
    }

    // MARK: - slip

    func testSlipChangesSourceInNotDurationOrPosition() {
        let s = seq3()
        let out = Mutations.slip(at: 1, delta: .seconds(1), assetDuration: .seconds(20), in: s)
        let c = clip(out, 1)!
        XCTAssertEqual(c.sourceIn.seconds, 3, accuracy: 0.001, "入点 +1")
        XCTAssertEqual(c.duration.seconds, 5, accuracy: 0.001, "时长不变")
        // 其它片段不变 → 位置不变
        XCTAssertEqual(clip(out, 0)!.duration.seconds, 5)
        XCTAssertEqual(clip(out, 2)!.duration.seconds, 5)
    }

    func testSlipNegativeClampsAtZero() {
        let s = seq3()  // sourceIn=2
        let out = Mutations.slip(at: 0, delta: .seconds(-10), assetDuration: .seconds(20), in: s)
        XCTAssertEqual(clip(out, 0)!.sourceIn.seconds, 0, accuracy: 0.001, "入点不低于0")
        XCTAssertEqual(clip(out, 0)!.duration.seconds, 5, accuracy: 0.001)
    }

    func testSlipClampsAtAssetTail() {
        let s = seq3()  // sourceIn=2, dur=5 → out=7; asset=8 → maxIn=3
        let out = Mutations.slip(at: 0, delta: .seconds(10), assetDuration: .seconds(8), in: s)
        XCTAssertEqual(clip(out, 0)!.sourceIn.seconds, 3, accuracy: 0.001, "入点不超过 assetDur-dur=3")
        XCTAssertEqual(clip(out, 0)!.duration.seconds, 5, accuracy: 0.001)
    }

    // MARK: - slide

    func testSlideRightExtendsPrevShrinksNext() {
        let s = seq3()
        let out = Mutations.slide(at: 1, delta: .seconds(1),
                                  prevAssetDuration: .seconds(20), nextAssetDuration: .seconds(20), in: s)
        XCTAssertEqual(clip(out, 0)!.duration.seconds, 6, accuracy: 0.001, "前片段 +1")
        XCTAssertEqual(clip(out, 1)!.duration.seconds, 5, accuracy: 0.001, "自身时长不变")
        XCTAssertEqual(clip(out, 2)!.duration.seconds, 4, accuracy: 0.001, "后片段 -1")
        XCTAssertEqual(clip(out, 2)!.sourceIn.seconds, 3, accuracy: 0.001, "后片段头部 +1(sourceIn 2→3)")
    }

    func testSlideKeepsTotalDuration() {
        let s = seq3()
        let before = s.spine.reduce(0.0) { $0 + $1.duration.seconds }
        let out = Mutations.slide(at: 1, delta: .seconds(2),
                                  prevAssetDuration: .seconds(20), nextAssetDuration: .seconds(20), in: s)
        let after = out.spine.reduce(0.0) { $0 + $1.duration.seconds }
        XCTAssertEqual(before, after, accuracy: 0.001, "slide 不改总时长")
    }

    func testSlideClampedByNextDuration() {
        let s = seq3()  // next dur=5 → 最多裁 5-tick
        let out = Mutations.slide(at: 1, delta: .seconds(99),
                                  prevAssetDuration: .seconds(100), nextAssetDuration: .seconds(100), in: s)
        // next 时长不得 ≤ 0
        XCTAssertGreaterThan(clip(out, 2)!.duration.seconds, 0)
        XCTAssertLessThan(clip(out, 2)!.duration.seconds, 0.02, "后片段被裁到约 1 tick")
    }

    func testSlideNegativeShrinksPrevExtendsNext() {
        let s = seq3()  // next sourceIn=2 → 头部最多回退2
        let out = Mutations.slide(at: 1, delta: .seconds(-1),
                                  prevAssetDuration: .seconds(20), nextAssetDuration: .seconds(20), in: s)
        XCTAssertEqual(clip(out, 0)!.duration.seconds, 4, accuracy: 0.001, "前片段 -1")
        XCTAssertEqual(clip(out, 2)!.duration.seconds, 6, accuracy: 0.001, "后片段 +1")
        XCTAssertEqual(clip(out, 2)!.sourceIn.seconds, 1, accuracy: 0.001, "后片段头部回退(sourceIn 2→1)")
    }

    func testSlideAtEdgeNoNeighborIsNoOp() {
        let s = seq3()
        let out = Mutations.slide(at: 0, delta: .seconds(1),
                                  prevAssetDuration: .seconds(20), nextAssetDuration: .seconds(20), in: s)
        // index0 没有前邻 → 不变
        XCTAssertEqual(clip(out, 0)!.duration.seconds, 5)
        XCTAssertEqual(clip(out, 1)!.duration.seconds, 5)
    }
}
