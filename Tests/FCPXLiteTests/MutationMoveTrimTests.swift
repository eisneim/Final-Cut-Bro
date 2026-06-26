import XCTest
@testable import FCPXLite

final class MutationMoveTrimTests: XCTestCase {
    private func clip(_ secs: Double, sourceIn: Time = .zero) -> Clip {
        Clip(assetID: AssetID(), sourceIn: sourceIn, duration: .seconds(secs))
    }

    func testMoveReorders() {
        let a = clip(2), b = clip(3), c = clip(1)
        let seq0 = Sequence(spine: [.clip(a), .clip(b), .clip(c)])
        let seq1 = Mutations.moveClip(from: 0, to: 2, in: seq0) // A 移到末尾
        let ids = seq1.spine.compactMap { $0.asClip?.id }
        XCTAssertEqual(ids, [b.id, c.id, a.id])
        // 位置:B(3)@0, C(1)@3, A(2)@4
        XCTAssertEqual(Layout.compute(seq1).map(\.absStart),
                       [.seconds(0), .seconds(3), .seconds(4)])
    }

    func testRippleTrimRightShortens() {
        let seq0 = Sequence(spine: [.clip(clip(5)), .clip(clip(2))])
        // 把第0个从 5s 裁到 3s,素材总长 10s
        let seq1 = Mutations.rippleTrimRight(at: 0, newDuration: .seconds(3),
                                             assetDuration: .seconds(10), in: seq0)
        XCTAssertEqual(seq1.spine[0].duration, .seconds(3))
        // 后续 clip 跟着左移:第二个 @3
        XCTAssertEqual(Layout.compute(seq1).map(\.absStart), [.seconds(0), .seconds(3)])
    }

    func testRippleTrimRightClampsToAsset() {
        let seq0 = Sequence(spine: [.clip(clip(5))])
        // 试图裁长到 20s,但素材只有 8s(sourceIn=0)→ 夹到 8s
        let seq1 = Mutations.rippleTrimRight(at: 0, newDuration: .seconds(20),
                                             assetDuration: .seconds(8), in: seq0)
        XCTAssertEqual(seq1.spine[0].duration, .seconds(8))
    }

    func testRippleTrimLeftAdjustsSourceInAndDuration() {
        // clip sourceIn=2, duration=5(用素材 [2,7]);左边缘内移 1s → sourceIn=3, duration=4
        let seq0 = Sequence(spine: [.clip(clip(5, sourceIn: .seconds(2)))])
        let seq1 = Mutations.rippleTrimLeft(at: 0, deltaIn: .seconds(1),
                                            assetDuration: .seconds(10), in: seq0)
        XCTAssertEqual(seq1.spine[0].asClip?.sourceIn, .seconds(3))
        XCTAssertEqual(seq1.spine[0].duration, .seconds(4))
    }
}
