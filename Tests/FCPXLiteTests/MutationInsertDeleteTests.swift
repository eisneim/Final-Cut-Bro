import XCTest
@testable import FCPXLite

final class MutationInsertDeleteTests: XCTestCase {
    private func clip(_ secs: Double) -> Clip {
        Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(secs))
    }

    func testInsertShiftsLaterClips() {
        let seq0 = Sequence(spine: [.clip(clip(2)), .clip(clip(3))])
        let seq1 = Mutations.insertClip(clip(1), at: 1, in: seq0)
        let pos = Layout.compute(seq1).map(\.absStart)
        // [A(2)@0, NEW(1)@2, B(3)@3]
        XCTAssertEqual(pos, [.seconds(0), .seconds(2), .seconds(3)])
    }

    func testRippleDeleteCollapsesGap() {
        let seq0 = Sequence(spine: [.clip(clip(2)), .clip(clip(3)), .clip(clip(1))])
        let seq1 = Mutations.rippleDelete(at: 1, in: seq0) // 删中间 3s
        let pos = Layout.compute(seq1).map(\.absStart)
        // [A(2)@0, C(1)@2]  ← 合拢
        XCTAssertEqual(pos, [.seconds(0), .seconds(2)])
    }

    func testLiftDeleteKeepsHole() {
        let seq0 = Sequence(spine: [.clip(clip(2)), .clip(clip(3)), .clip(clip(1))])
        let seq1 = Mutations.liftDelete(at: 1, in: seq0)
        let pos = Layout.compute(seq1).map(\.absStart)
        // gap 占位,C 仍在 @5
        XCTAssertEqual(pos, [.seconds(0), .seconds(5)])
    }
}
